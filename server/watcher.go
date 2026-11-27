package main

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var (
	reBlockBreak = regexp.MustCompile(`(?i)<br\s*/?>|</p>|</div>|</tr>|<li[^>]*>`)
	reHTMLTag    = regexp.MustCompile(`<[^>]+>`)
	reWhitespace = regexp.MustCompile(`\s+`)
)

func cleanHTMLText(s string) string {
	if s == "" {
		return ""
	}
	s = reBlockBreak.ReplaceAllString(s, " ")
	s = reHTMLTag.ReplaceAllString(s, "")
	s = html.UnescapeString(s)
	s = strings.ReplaceAll(s, "\u00a0", " ")
	s = reWhitespace.ReplaceAllString(s, " ")
	return strings.TrimSpace(s)
}

func truncateRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return strings.TrimSpace(string(r[:max])) + "…"
}

// State remembers what was already seen. A nil set means "first run": the current content is
// stored silently so you aren't flooded with your whole history.
type State struct {
	Marks       map[string]bool `json:"marks"`
	Komens      map[string]bool `json:"komens"`
	Noticeboard map[string]bool `json:"noticeboard"`
	Changes     map[string]bool `json:"changes"`
}

type Watcher struct {
	reg      Registration
	client   *Client
	apns     *APNs
	path     string
	state    State
	devices  func(id string) []Device
	dropDead func(id, token string)
}

func NewWatcher(reg Registration, apns *APNs, dataDir string, devices func(id string) []Device, dropDead func(id, token string)) *Watcher {
	w := &Watcher{
		reg:      reg,
		client:   NewClient(reg.SchoolURL, reg.Username, reg.Password),
		apns:     apns,
		path:     filepath.Join(dataDir, "state-"+reg.ID+".json"),
		devices:  devices,
		dropDead: dropDead,
	}
	if data, err := os.ReadFile(w.path); err == nil {
		_ = json.Unmarshal(data, &w.state)
	}
	return w
}

func (w *Watcher) save() {
	data, err := json.Marshal(w.state)
	if err != nil {
		return
	}
	tmp := w.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err == nil {
		_ = os.Rename(tmp, w.path)
	}
}

func (w *Watcher) Run(ctx context.Context, every time.Duration) {
	w.check(ctx)
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			w.check(ctx)
		}
	}
}

func (w *Watcher) logf(format string, args ...any) {
	log.Printf("[%s@%s] %s", w.reg.Username, w.reg.SchoolURL, fmt.Sprintf(format, args...))
}

// send pushes to every device of the account. It reports success if at least one delivery worked
// (or there is nobody to notify), so an item isn't retried forever because one phone is gone.
func (w *Watcher) send(title, message, route string) bool {
	devices := w.devices(w.reg.ID)
	if len(devices) == 0 {
		return true
	}
	delivered := false
	for _, d := range devices {
		switch err := w.apns.Send(d, title, message, route); err {
		case nil:
			delivered = true
		case errDeadToken:
			w.dropDead(w.reg.ID, d.Token)
		default:
			w.logf("push failed: %v", err)
		}
	}
	return delivered
}

func (w *Watcher) check(ctx context.Context) {
	if w.reg.Marks && ctx.Err() == nil {
		if r, err := w.client.Marks(ctx); err != nil {
			if ctx.Err() == nil {
				w.logf("marks: %v", err)
			}
		} else {
			w.processMarks(r)
		}
	}
	if w.reg.Komens && ctx.Err() == nil {
		if m, err := w.client.Messages(ctx, "received"); err != nil {
			if ctx.Err() == nil {
				w.logf("komens: %v", err)
			}
		} else {
			w.processMessages(m, &w.state.Komens, "Komens", "komens", true)
		}
	}
	if w.reg.Noticeboard && ctx.Err() == nil {
		if m, err := w.client.Messages(ctx, "noticeboard"); err != nil {
			if ctx.Err() == nil {
				w.logf("noticeboard: %v", err)
			}
		} else {
			w.processMessages(m, &w.state.Noticeboard, "Nástěnka", "noticeboard", false)
		}
	}
	if w.reg.Timetable && ctx.Err() == nil {
		w.processTimetable(ctx)
	}
	w.save()
}

// diffNew returns the ids not in *seen and updates *seen. Only ids that were delivered are
// remembered, so a failed publish is retried on the next poll. On the first run (*seen == nil)
// everything is recorded silently.
func diffNew(seen *map[string]bool, ids []string, deliver func(id string) bool) {
	first := *seen == nil
	if first {
		*seen = map[string]bool{}
	}
	for _, id := range ids {
		if (*seen)[id] {
			continue
		}
		if first || deliver(id) {
			(*seen)[id] = true
		}
	}
}

func (w *Watcher) processMarks(r *MarksResponse) {
	type item struct {
		subject string
		mark    Mark
	}
	byID := map[string]item{}
	var ids []string
	for _, s := range r.Subjects {
		for _, m := range s.Marks {
			byID[m.ID] = item{s.Subject.Display(), m}
			ids = append(ids, m.ID)
		}
	}
	diffNew(&w.state.Marks, ids, func(id string) bool {
		it := byID[id]
		body := strings.TrimSpace(it.mark.Caption)
		if body == "" {
			body = strings.TrimSpace(it.mark.Theme)
		}
		body = truncateRunes(body, 240)
		return w.send(fmt.Sprintf("%s: %s", it.subject, it.mark.MarkText), body, "marks")
	})
}

func (w *Watcher) processMessages(msgs []Message, seen *map[string]bool, label, route string, skipRead bool) {
	byID := map[string]Message{}
	var ids []string
	for _, m := range msgs {
		byID[m.ID] = m
		ids = append(ids, m.ID)
	}
	diffNew(seen, ids, func(id string) bool {
		m := byID[id]
		if skipRead && m.Read != nil && *m.Read {
			return true
		}
		title := label
		sender := strings.TrimSpace(m.Sender.Name)
		if sender == "" {
			sender = strings.TrimSpace(m.RelevantName)
		}
		if sender != "" {
			title += ": " + sender
		}
		body := strings.TrimSpace(m.Title)
		preview := cleanHTMLText(m.Text)
		if body == "" {
			body = preview
		} else if preview != "" {
			body += " · " + preview
		}
		body = truncateRunes(body, 240)
		return w.send(title, body, route)
	})
}

func (w *Watcher) processTimetable(ctx context.Context) {
	now := time.Now()
	var weeks []*TimetableResponse
	for _, d := range []time.Time{now, now.AddDate(0, 0, 7)} {
		r, err := w.client.Timetable(ctx, d)
		if err != nil {
			if ctx.Err() == nil {
				w.logf("timetable: %v", err)
			}
			return
		}
		weeks = append(weeks, r)
	}

	today := now.Format("2006-01-02")
	byID := map[string]string{}
	var ids []string
	for _, r := range weeks {
		subjects := map[string]string{}
		for _, s := range r.Subjects {
			subjects[s.ID] = s.Display()
		}
		hours := map[int]string{}
		for _, h := range r.Hours {
			hours[h.ID] = h.Caption
		}
		for _, day := range r.Days {
			date := day.Date
			if len(date) >= 10 {
				date = date[:10]
			}
			if date < today {
				continue
			}
			for _, a := range day.Atoms {
				if a.Change == nil {
					continue
				}
				desc := strings.TrimSpace(a.Change.Description)
				if desc == "" {
					desc = strings.TrimSpace(a.Change.TypeName)
				}
				if desc == "" {
					desc = strings.TrimSpace(a.Change.ChangeType)
				}
				id := fmt.Sprintf("%s|%d|%s", date, a.HourID, desc)
				name := subjects[a.SubjectID]
				if name == "" {
					name = "Hodina"
				}
				byID[id] = truncateRunes(fmt.Sprintf("%s, %s. hodina\n%s", date, hours[a.HourID], name+": "+desc), 240)
				ids = append(ids, id)
			}
		}
	}
	diffNew(&w.state.Changes, ids, func(id string) bool {
		return w.send("Změna v rozvrhu", byID[id], "timetable")
	})
	// Drop changes for days that are over, so the state doesn't grow forever.
	for id := range w.state.Changes {
		if len(id) >= 10 && id[:10] < today {
			delete(w.state.Changes, id)
		}
	}
}
