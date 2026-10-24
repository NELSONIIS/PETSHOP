package main

import (
	"fmt"
	"time"

	"petora/internal/security"
)

func main() {
	box, err := security.NewBox("MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=")
	if err != nil {
		panic(err)
	}
	secret, err := box.Open("XzB5pvkz0BdyqjuE/8lDP3B8m/cU1CiOuVHmbzTTAZ8hIVCg3CzUirBHbn4PeOckZpAFsolsskUfoGQh")
	if err != nil {
		panic(err)
	}
	fmt.Printf("%s\n", security.TOTPCode(secret, time.Now()))
}
