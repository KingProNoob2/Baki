package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type Device struct {
	Token   string `json:"token"`
	Sandbox bool   `json:"sandbox"` // true for builds run from Xcode
}

// Registration is one Bakaláři account and the phones that should be notified about it.
type Registration struct {
	ID          string   `json:"id"`
	SchoolURL   string   `json:"school_url"`
	Username    string   `json:"username"`
	Password    string   `json:"password"`
	Marks       bool     `json:"marks"`
	Komens      bool     `json:"komens"`
	Noticeboard bool     `json:"noticeboard"`
	Timetable   bool     `json:"timetable"`
	Devices     []Device `json:"devices"`
}

func registrationID(schoolURL, username string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimRight(schoolURL, "/")) + "\n" + strings.ToLower(username)))
	return hex.EncodeToString(sum[:8])
}

// Manager owns all registrations and runs one watcher per account.
type Manager struct {
	ctx  context.Context
	cfg  *Config
	apns *APNs
	path string

	mu       sync.Mutex
	regs     map[string]*Registration
	watchers map[string]context.CancelFunc
	wg       sync.WaitGroup
}

func NewManager(ctx context.Context, cfg *Config, apns *APNs) *Manager {
	m := &Manager{
		ctx:      ctx,
		cfg:      cfg,
		apns:     apns,
		path:     filepath.Join(cfg.DataDir, "registrations.json"),
		regs:     map[string]*Registration{},
		watchers: map[string]context.CancelFunc{},
	}
	return m
}

func (m *Manager) Start() {
	m.mu.Lock()
	defer m.mu.Unlock()
	if data, err := os.ReadFile(m.path); err == nil {
		var list []*Registration
		if json.Unmarshal(data, &list) == nil {
			for _, r := range list {
				m.regs[r.ID] = r
				m.startWatcherLocked(r)
			}
		}
	}
	log.Printf("loaded %d registration(s)", len(m.regs))
}

func (m *Manager) Wait() { m.wg.Wait() }

func (m *Manager) saveLocked() {
	list := make([]*Registration, 0, len(m.regs))
	for _, r := range m.regs {
		list = append(list, r)
	}
	data, err := json.Marshal(list)
	if err != nil {
		return
	}
	tmp := m.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err == nil {
		_ = os.Rename(tmp, m.path)
	}
}

func (m *Manager) startWatcherLocked(r *Registration) {
	if cancel, ok := m.watchers[r.ID]; ok {
		cancel()
	}
	ctx, cancel := context.WithCancel(m.ctx)
	m.watchers[r.ID] = cancel
	w := NewWatcher(*r, m.apns, m.cfg.DataDir, m.DevicesFor, m.dropDevice)
	m.wg.Add(1)
	go func() {
		defer m.wg.Done()
		w.Run(ctx, time.Duration(m.cfg.PollSeconds)*time.Second)
	}()
}

// Register adds or updates an account and makes sure the device is subscribed to it.
func (m *Manager) Register(r Registration, device Device) {
	r.ID = registrationID(r.SchoolURL, r.Username)
	m.mu.Lock()
	defer m.mu.Unlock()
	if old, ok := m.regs[r.ID]; ok {
		r.Devices = old.Devices
	}
	found := false
	for i, d := range r.Devices {
		if d.Token == device.Token {
			r.Devices[i] = device
			found = true
		}
	}
	if !found {
		r.Devices = append(r.Devices, device)
	}
	m.regs[r.ID] = &r
	m.saveLocked()
	m.startWatcherLocked(&r)
}

// Unregister removes a device; the account is dropped (and its watcher stopped) when none are left.
func (m *Manager) Unregister(schoolURL, username, token string) {
	m.dropDevice(registrationID(schoolURL, username), token)
}

func (m *Manager) dropDevice(id, token string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.regs[id]
	if !ok {
		return
	}
	kept := r.Devices[:0:0]
	for _, d := range r.Devices {
		if d.Token != token {
			kept = append(kept, d)
		}
	}
	r.Devices = kept
	if len(kept) == 0 {
		if cancel, ok := m.watchers[id]; ok {
			cancel()
			delete(m.watchers, id)
		}
		delete(m.regs, id)
		_ = os.Remove(filepath.Join(m.cfg.DataDir, "state-"+id+".json"))
	}
	m.saveLocked()
}

// DevicesFor returns the current devices of an account.
func (m *Manager) DevicesFor(id string) []Device {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r, ok := m.regs[id]; ok {
		return append([]Device(nil), r.Devices...)
	}
	return nil
}

// Update changes the categories and device of an already registered account without needing the
// password. It reports false if the account isn't registered.
func (m *Manager) Update(schoolURL, username string, marks, komens, noticeboard, timetable bool, device Device) bool {
	id := registrationID(schoolURL, username)
	m.mu.Lock()
	defer m.mu.Unlock()
	old, ok := m.regs[id]
	if !ok {
		return false
	}
	r := *old
	r.Marks, r.Komens, r.Noticeboard, r.Timetable = marks, komens, noticeboard, timetable
	r.Devices = append([]Device(nil), old.Devices...)
	found := false
	for i, d := range r.Devices {
		if d.Token == device.Token {
			r.Devices[i] = device
			found = true
		}
	}
	if !found {
		r.Devices = append(r.Devices, device)
	}
	m.regs[id] = &r
	m.saveLocked()
	m.startWatcherLocked(&r)
	return true
}
