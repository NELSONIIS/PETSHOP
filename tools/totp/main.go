package main

import (
	"fmt"
	"os"
	"time"

	"petora/internal/security"
)

func main() { fmt.Print(security.TOTPCode(os.Args[1], time.Now())) }
