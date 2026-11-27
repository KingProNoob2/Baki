package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"os"
	"sync"
	"time"
)

type APNsConfig struct {
	KeyFile  string `json:"key_file"`  // the AuthKey_XXXX.p8 downloaded from developer.apple.com
	KeyID    string `json:"key_id"`    // 10 characters, from the key's name
	TeamID   string `json:"team_id"`   // 10 characters
	BundleID string `json:"bundle_id"` // the app's bundle identifier, e.g. com.example.Baki
}

// APNs sends pushes straight to Apple over HTTP/2 using token-based auth.
type APNs struct {
	cfg    APNsConfig
	key    *ecdsa.PrivateKey
	client *http.Client

	mu       sync.Mutex
	jwt      string
	jwtMade  time.Time
}

func NewAPNs(cfg APNsConfig) (*APNs, error) {
	raw, err := os.ReadFile(cfg.KeyFile)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, fmt.Errorf("%s is not a PEM file", cfg.KeyFile)
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("%s is not an EC key", cfg.KeyFile)
	}
	return &APNs{
		cfg: cfg,
		key: key,
		client: &http.Client{
			Timeout:   15 * time.Second,
			Transport: &http.Transport{ForceAttemptHTTP2: true},
		},
	}, nil
}

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// token returns a provider token. Apple wants it refreshed between 20 and 60 minutes.
func (a *APNs) token() (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.jwt != "" && time.Since(a.jwtMade) < 40*time.Minute {
		return a.jwt, nil
	}
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": a.cfg.KeyID})
	claims, _ := json.Marshal(map[string]any{"iss": a.cfg.TeamID, "iat": time.Now().Unix()})
	signing := b64(header) + "." + b64(claims)
	digest := sha256.Sum256([]byte(signing))
	r, s, err := ecdsa.Sign(rand.Reader, a.key, digest[:])
	if err != nil {
		return "", err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	a.jwt = signing + "." + b64(sig)
	a.jwtMade = time.Now()
	return a.jwt, nil
}

// errDeadToken means Apple says the device token is no longer valid and should be dropped.
var errDeadToken = fmt.Errorf("device token is no longer valid")

func (a *APNs) Send(d Device, title, body, route string) error {
	jwt, err := a.token()
	if err != nil {
		return err
	}
	host := "api.push.apple.com"
	if d.Sandbox {
		host = "api.sandbox.push.apple.com"
	}
	aps := map[string]any{
		"alert": map[string]string{"title": title, "body": body},
		"sound": "default",
	}
	if route != "" {
		aps["thread-id"] = route
	}
	root := map[string]any{"aps": aps}
	if route != "" {
		root["route"] = route
	}
	payload, _ := json.Marshal(root)
	req, err := http.NewRequest("POST", "https://"+host+"/3/device/"+d.Token, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+jwt)
	req.Header.Set("apns-topic", a.cfg.BundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	var reason struct {
		Reason string `json:"reason"`
	}
	data, _ := io.ReadAll(resp.Body)
	_ = json.Unmarshal(data, &reason)
	if resp.StatusCode == http.StatusGone || reason.Reason == "BadDeviceToken" || reason.Reason == "Unregistered" || reason.Reason == "DeviceTokenNotForTopic" {
		return errDeadToken
	}
	return fmt.Errorf("apns: HTTP %d %s", resp.StatusCode, reason.Reason)
}
