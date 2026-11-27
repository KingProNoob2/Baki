package main

import (
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
)

var hexToken = regexp.MustCompile(`^[0-9a-fA-F]{32,200}$`)

type registerRequest struct {
	SchoolURL   string `json:"school_url"`
	Username    string `json:"username"`
	Password    string `json:"password"`
	DeviceToken string `json:"device_token"`
	Sandbox     bool   `json:"sandbox"`
	Marks       bool   `json:"marks"`
	Komens      bool   `json:"komens"`
	Noticeboard bool   `json:"noticeboard"`
	Timetable   bool   `json:"timetable"`
}

func newAPI(cfg *Config, mgr *Manager) http.Handler {
	mux := http.NewServeMux()

	authed := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			got := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
			if subtle.ConstantTimeCompare([]byte(got), []byte(cfg.APIKey)) != 1 {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			r.Body = http.MaxBytesReader(w, r.Body, 1<<16)
			next(w, r)
		}
	}

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("POST /v1/register", authed(func(w http.ResponseWriter, r *http.Request) {
		var req registerRequest
		if json.NewDecoder(r.Body).Decode(&req) != nil || req.SchoolURL == "" || req.Username == "" ||
			req.Password == "" || !hexToken.MatchString(req.DeviceToken) {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		// Check the login first so a typo is reported to the app right away.
		if err := NewClient(req.SchoolURL, req.Username, req.Password).authenticate(r.Context()); err != nil {
			http.Error(w, "Bakaláři login failed", http.StatusForbidden)
			return
		}
		mgr.Register(Registration{
			SchoolURL:   req.SchoolURL,
			Username:    req.Username,
			Password:    req.Password,
			Marks:       req.Marks,
			Komens:      req.Komens,
			Noticeboard: req.Noticeboard,
			Timetable:   req.Timetable,
		}, Device{Token: strings.ToLower(req.DeviceToken), Sandbox: req.Sandbox})
		w.WriteHeader(http.StatusNoContent)
	}))

	mux.HandleFunc("POST /v1/update", authed(func(w http.ResponseWriter, r *http.Request) {
		var req registerRequest
		if json.NewDecoder(r.Body).Decode(&req) != nil || req.SchoolURL == "" || req.Username == "" ||
			!hexToken.MatchString(req.DeviceToken) {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if !mgr.Update(req.SchoolURL, req.Username, req.Marks, req.Komens, req.Noticeboard, req.Timetable,
			Device{Token: strings.ToLower(req.DeviceToken), Sandbox: req.Sandbox}) {
			http.Error(w, "not registered", http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))

	mux.HandleFunc("POST /v1/unregister", authed(func(w http.ResponseWriter, r *http.Request) {
		var req registerRequest
		if json.NewDecoder(r.Body).Decode(&req) != nil || req.SchoolURL == "" || req.Username == "" || req.DeviceToken == "" {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		mgr.Unregister(req.SchoolURL, req.Username, strings.ToLower(req.DeviceToken))
		w.WriteHeader(http.StatusNoContent)
	}))

	return mux
}
