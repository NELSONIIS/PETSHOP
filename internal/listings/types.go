// Package listings implements pet listing discovery, detail, the seller listing workflow,
// image handling, favourites, views and analytics.
package listings

import (
	"encoding/json"
	"time"

	"petora/internal/sellers"
)

// Disclaimer is shown with every listing. PETORA does not verify animal health.
const Disclaimer = "Health, vaccination and pedigree details are declared by the seller and have not been verified by PETORA. " +
	"Meet the pet in person, ask for veterinary records, never pay in advance to unknown sellers, and follow local animal-welfare laws."

type Ref struct {
	ID   string `json:"id"`
	Slug string `json:"slug"`
	Name string `json:"name"`
}

type Variants struct {
	Thumb  string `json:"thumb"`
	Medium string `json:"medium"`
	Large  string `json:"large"`
}

type Card struct {
	ID                string        `json:"id"`
	Slug              string        `json:"slug"`
	Title             string        `json:"title"`
	ListingType       string        `json:"listing_type"`
	PriceMinor        int64         `json:"price_minor"`
	Currency          string        `json:"currency"`
	AgeMonths         *int          `json:"age_months"`
	Gender            string        `json:"gender"`
	City              string        `json:"city"`
	State             string        `json:"state"`
	Category          Ref           `json:"category"`
	Breed             *Ref          `json:"breed"`
	Cover             *Variants     `json:"cover"`
	Seller            sellers.Badge `json:"seller"`
	Availability      string        `json:"availability"`
	VaccinationStatus string        `json:"vaccination_status"`
	Featured          bool          `json:"featured"`
	IsFavourite       bool          `json:"is_favourite"`
	DistanceKm        *float64      `json:"distance_km"`
	PublishedAt       *time.Time    `json:"published_at"`
}

type Image struct {
	ID       string `json:"id"`
	Thumb    string `json:"thumb"`
	Medium   string `json:"medium"`
	Large    string `json:"large"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
	Position int    `json:"position"`
	IsCover  bool   `json:"is_cover"`
	AltText  string `json:"alt_text"`
}

type ContactState struct {
	Unlocked           bool `json:"unlocked"`
	RequiresMembership bool `json:"requires_membership"`
}

type Detail struct {
	Card
	Description      string            `json:"description"`
	Colour           string            `json:"colour"`
	VaccinationNotes string            `json:"vaccination_notes"`
	HealthNotes      string            `json:"health_notes"`
	Dewormed         *bool             `json:"dewormed"`
	Microchipped     *bool             `json:"microchipped"`
	Images           []Image           `json:"images"`
	Attributes       map[string]string `json:"attributes"`
	ViewsCount       int               `json:"views_count"`
	SellerProfile    *sellers.Public   `json:"seller_profile"`
	Contact          ContactState      `json:"contact"`
	Disclaimer       string            `json:"disclaimer"`
}

type ModerationEvent struct {
	Action    string          `json:"action"`
	Reason    *string         `json:"reason"`
	Flags     json.RawMessage `json:"flags"`
	Moderator *string         `json:"moderator"`
	CreatedAt time.Time       `json:"created_at"`
}

type Owner struct {
	Detail
	Status               string            `json:"status"`
	RejectionReason      *string           `json:"rejection_reason"`
	ExpiredReason        *string           `json:"expired_reason"`
	FavouritesCount      int               `json:"favourites_count"`
	EnquiriesCount       int               `json:"enquiries_count"`
	ExpiresAt            *time.Time        `json:"expires_at"`
	CreatedAt            time.Time         `json:"created_at"`
	UpdatedAt            time.Time         `json:"updated_at"`
	Moderation           []ModerationEvent `json:"moderation"`
	MissingForSubmission []string          `json:"missing_for_submission"`
	Lat                  *float64          `json:"lat"`
	Lng                  *float64          `json:"lng"`
}

type Input struct {
	Title             string            `json:"title"`
	Description       string            `json:"description"`
	CategoryID        string            `json:"category_id"`
	BreedID           *string           `json:"breed_id"`
	ListingType       string            `json:"listing_type"`
	PriceMinor        int64             `json:"price_minor"`
	Currency          string            `json:"currency,omitempty"`
	AgeMonths         *int              `json:"age_months"`
	Gender            string            `json:"gender"`
	Colour            string            `json:"colour"`
	VaccinationStatus string            `json:"vaccination_status"`
	VaccinationNotes  string            `json:"vaccination_notes"`
	HealthNotes       string            `json:"health_notes"`
	Dewormed          *bool             `json:"dewormed"`
	Microchipped      *bool             `json:"microchipped"`
	City              string            `json:"city"`
	State             string            `json:"state"`
	Lat               *float64          `json:"lat"`
	Lng               *float64          `json:"lng"`
	Attributes        map[string]string `json:"attributes"`
}
