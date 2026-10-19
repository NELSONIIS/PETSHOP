package seed

const reviewNote = "\n\n---\n*Template text prepared for launch. It must be reviewed and approved by qualified legal counsel for your entity and the states you operate in before PETORA goes live.*"

var legalPages = map[string][2]string{
	"terms": {"Terms of Service", `# Terms of Service

PETORA is an online marketplace that lets people discover pets listed by independent sellers and rescues. PETORA is **not** a party to any sale, adoption or transport arrangement between users.

## Accounts
You must be 18 or older, give accurate information and keep your password secure. We may suspend accounts that break these terms or the law.

## Memberships and seller subscriptions
* Browsing is free. A buyer membership unlocks seller contact details and enquiries as described on the pricing page.
* A seller subscription allows publishing listings within the plan's allowance. Listings are moderated before going live.
* Paying for a plan does **not** guarantee that a pet is available, healthy, as described, or that a transaction will happen.
* Prices include applicable taxes as shown at checkout. See the Refund Policy for cancellations and refunds.

## Seller obligations
Sellers must comply with all applicable law, including the Prevention of Cruelty to Animals Act, 1960 and rules made under it (including the Dog Breeding and Marketing Rules, 2017 and the Pet Shop Rules, 2018, where they apply), the Wild Life (Protection) Act, 1972 and state regulations. Sellers are solely responsible for the accuracy of listings, health and vaccination disclosures, and any registration or licence they are legally required to hold.

## Prohibited content
Protected or wild species, animals that are too young to be separated from their mother, misleading health claims, and any listing that facilitates cruelty or illegal trade are prohibited and will be removed.

## Liability
To the extent permitted by law, PETORA is not liable for dealings between users. Nothing limits rights you have under the Consumer Protection Act, 2019.

## Contact
Questions: support@petora.in` + reviewNote},
	"privacy": {"Privacy Policy", `# Privacy Policy

We process personal data in accordance with the Digital Personal Data Protection Act, 2023.

## What we collect
* Account data: name, email, phone number, password (stored only as a secure hash).
* Seller verification documents: stored in private, access-controlled storage; viewed only by authorised staff; every access is logged.
* Usage data: listings viewed, favourites, enquiries and messages you send, payments (we never see or store full card or UPI credentials; payments are handled by our payment provider).

## Why we use it
To run the marketplace, verify sellers, prevent fraud and abuse, process payments and invoices, and send you service messages.

## Sharing
Seller contact details are shown only to buyers who unlock them under a valid membership. We share data with service providers (hosting, email, payments) under contract, and with authorities when required by law.

## Retention
Rejected verification documents are deleted after 90 days. Financial records are kept as required by tax law. You can delete your account at any time from Profile → Security; we then anonymise your personal data.

## Your rights
You can access, correct and erase your data and withdraw consent. Contact our Grievance Officer at privacy@petora.in.` + reviewNote},
	"refund-policy": {"Refund Policy", `# Refund Policy

* **Buyer memberships:** eligible for a full refund within the refund window shown on the plan (typically 7 days) if you have not unlocked any seller contact. After a contact is unlocked the membership is non-refundable.
* **Seller subscriptions:** non-refundable once activated, except where required by law or where PETORA could not provide the service.
* **Cancellation:** cancelling stops renewal reminders; benefits continue until the end of the paid period unless the plan states immediate cancellation.
* **Failed or duplicate payments:** if you were charged but your plan did not activate, contact support with your payment reference; verified duplicate charges are refunded in full.
* Refunds are returned to the original payment method. Processing times depend on your bank and our payment provider (usually 5–7 working days).` + reviewNote},
	"seller-policy": {"Seller Policy", `# Seller Policy

1. Complete seller verification with a valid identity document. Businesses (breeders, pet shops, kennels) must provide registration documents required in their state.
2. List only animals you are legally permitted to sell or rehome. Never list wild or protected species.
3. Disclose age, vaccination and health status honestly. Do not claim a pet is "vet certified" unless you can show the certificate to the buyer.
4. Use your own photos of the actual animal.
5. Respond to enquiries respectfully. Do not ask buyers for advance payments before they have met the animal.
6. PETORA may suspend listings or accounts that breach this policy, and may report illegal activity to authorities.` + reviewNote},
	"safety": {"Safety & responsible ownership", `# Buying or adopting safely

* **Meet in person** and see the pet with its mother where possible. Be wary of anyone who refuses a meeting or video call.
* **Never pay in advance** to someone you have not met, and never for "transport" or "insurance" fees on an animal you have not seen.
* **Ask for records:** vaccination card, deworming history and, for registered breeders, their registration with the State Animal Welfare Board.
* **Check age:** puppies and kittens should not leave their mother before 8 weeks.
* **Verified seller** on PETORA means our team reviewed the seller's identity or business documents. It is not a guarantee of the animal's health.
* **Adopt responsibly:** consider rescues and adoption listings, and be ready for the lifetime cost and care of your pet.
* **Report** suspicious listings or messages using the Report button; our moderators review every report.`},
}

var contentBlocks = map[string]any{
	"home": map[string]any{
		"hero_title":    "Find your next companion",
		"hero_subtitle": "Browse pets from verified sellers and rescues near you. Free to browse — unlock contacts when you're ready.",
		"how_it_works": []map[string]string{
			{"title": "Browse free", "body": "Search by species, breed, age and location."},
			{"title": "Unlock contact", "body": "A membership reveals the seller's phone and lets you send enquiries."},
			{"title": "Meet safely", "body": "Meet the pet in person, check records, then decide."},
		},
		"adoption_title": "Adopt, don't shop",
		"adoption_body":  "Rescues and owners list pets for adoption free of charge to buyers.",
	},
	"faq": map[string]any{"items": []map[string]string{
		{"q": "Is browsing free?", "a": "Yes. Anyone can search and view listings without paying."},
		{"q": "What does a membership unlock?", "a": "Seller contact details (phone/WhatsApp/email) and enquiries, within your plan's allowance."},
		{"q": "Does a membership guarantee a pet?", "a": "No. Availability and the transaction are between you and the seller. Meet the pet before paying the seller anything."},
		{"q": "What does 'Verified seller' mean?", "a": "Our team reviewed the seller's identity or business documents. It does not certify the animal's health."},
		{"q": "How do I become a seller?", "a": "Register as a seller, complete verification, choose a seller plan, then add your pets for moderation."},
		{"q": "Can I get a refund?", "a": "See the Refund Policy. Buyer memberships are refundable within the refund window if no contacts were unlocked."},
	}},
}
