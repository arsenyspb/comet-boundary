package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRootHandler(t *testing.T) {
	r := setupRouter()
	ts := httptest.NewServer(r)
	defer ts.Close()

	res, err := http.Get(ts.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != http.StatusOK {
		t.Errorf("Expected status OK; got %v", res.Status)
	}
}

func TestLogin_MissingCredentials(t *testing.T) {
	r := setupRouter()
	ts := httptest.NewServer(r)
	defer ts.Close()

	// Missing password
	reqBody, _ := json.Marshal(map[string]string{
		"login_name": "admin",
	})
	req, _ := http.NewRequest("POST", ts.URL+"/auth/login", bytes.NewBuffer(reqBody))
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}

	if res.StatusCode != http.StatusBadRequest {
		t.Errorf("Expected status BadRequest (400) for missing credentials; got %v", res.Status)
	}
}
