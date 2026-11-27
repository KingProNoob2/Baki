package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// Client talks to one school's Bakaláři API and keeps its token fresh.
type Client struct {
	base, username, password string
	http                     *http.Client

	mu           sync.Mutex
	bearer       string
	refreshToken string
}

func NewClient(schoolURL, username, password string) *Client {
	base := strings.TrimSpace(schoolURL)
	if !strings.HasPrefix(base, "http://") && !strings.HasPrefix(base, "https://") {
		base = "https://" + base
	}
	return &Client{
		base:     strings.TrimRight(base, "/"),
		username: username,
		password: password,
		http:     &http.Client{Timeout: 20 * time.Second},
	}
}

func (c *Client) tokenRequest(ctx context.Context, form url.Values) error {
	form.Set("client_id", "ANDR")
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+"/api/login", strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("login: HTTP %d", resp.StatusCode)
	}
	var tok struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.Unmarshal(body, &tok); err != nil || tok.AccessToken == "" {
		return fmt.Errorf("login: unreadable token response")
	}
	c.bearer = tok.AccessToken
	if tok.RefreshToken != "" {
		c.refreshToken = tok.RefreshToken
	}
	return nil
}

// authenticate tries the refresh token first and falls back to the password.
func (c *Client) authenticate(ctx context.Context) error {
	if c.refreshToken != "" {
		err := c.tokenRequest(ctx, url.Values{"grant_type": {"refresh_token"}, "refresh_token": {c.refreshToken}})
		if err == nil {
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
	}
	return c.tokenRequest(ctx, url.Values{"grant_type": {"password"}, "username": {c.username}, "password": {c.password}})
}

func (c *Client) get(ctx context.Context, path, method string, out any) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	do := func() (int, []byte, error) {
		req, err := http.NewRequestWithContext(ctx, method, c.base+path, nil)
		if err != nil {
			return 0, nil, err
		}
		req.Header.Set("Authorization", "Bearer "+c.bearer)
		resp, err := c.http.Do(req)
		if err != nil {
			return 0, nil, err
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		return resp.StatusCode, body, err
	}

	if c.bearer == "" {
		if err := c.authenticate(ctx); err != nil {
			return err
		}
	}
	status, body, err := do()
	if err == nil && status == http.StatusUnauthorized {
		if err = c.authenticate(ctx); err != nil {
			return err
		}
		status, body, err = do()
	}
	if err != nil {
		return err
	}
	if status < 200 || status > 299 {
		return fmt.Errorf("%s: HTTP %d", path, status)
	}
	return json.Unmarshal(body, out)
}

type Subject struct {
	ID     string `json:"Id"`
	Abbrev string `json:"Abbrev"`
	Name   string `json:"Name"`
}

func (s Subject) Display() string {
	if s.Name != "" {
		return s.Name
	}
	return s.Abbrev
}

type Mark struct {
	ID       string `json:"Id"`
	MarkText string `json:"MarkText"`
	Caption  string `json:"Caption"`
	Theme    string `json:"Theme"`
}

type MarksResponse struct {
	Subjects []struct {
		Marks   []Mark  `json:"Marks"`
		Subject Subject `json:"Subject"`
	} `json:"Subjects"`
}

type Message struct {
	ID           string `json:"Id"`
	Title        string `json:"Title"`
	Text         string `json:"Text"`
	Read         *bool  `json:"Read"`
	RelevantName string `json:"RelevantName"`
	Sender       struct {
		Name string `json:"Name"`
	} `json:"Sender"`
}

type MessagesResponse struct {
	Messages []Message `json:"Messages"`
}

type TimetableResponse struct {
	Hours []struct {
		ID      int    `json:"Id"`
		Caption string `json:"Caption"`
	} `json:"Hours"`
	Days []struct {
		Date  string `json:"Date"`
		Atoms []struct {
			HourID    int     `json:"HourId"`
			SubjectID string  `json:"SubjectId"`
			Change    *Change `json:"Change"`
		} `json:"Atoms"`
	} `json:"Days"`
	Subjects []Subject `json:"Subjects"`
}

type Change struct {
	ChangeType  string `json:"ChangeType"`
	Description string `json:"Description"`
	TypeName    string `json:"TypeName"`
}

func (c *Client) Marks(ctx context.Context) (*MarksResponse, error) {
	var r MarksResponse
	return &r, c.get(ctx, "/api/3/marks", "GET", &r)
}

func (c *Client) Messages(ctx context.Context, kind string) ([]Message, error) {
	var r MessagesResponse
	err := c.get(ctx, "/api/3/komens/messages/"+kind, "POST", &r)
	return r.Messages, err
}

func (c *Client) Timetable(ctx context.Context, date time.Time) (*TimetableResponse, error) {
	var r TimetableResponse
	return &r, c.get(ctx, "/api/3/timetable/actual?date="+date.Format("2006-01-02"), "GET", &r)
}
