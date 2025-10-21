install: # Install everything needed to build this project
	mkdir -p .bin

	echo "Installing elm..."
	curl -L -o elm.gz https://github.com/elm/compiler/releases/download/0.19.1/binary-for-linux-64-bit.gz
	gunzip elm.gz
	chmod +x elm
	mv elm .bin/

	python3.13 -m venv .venv
	.venv/bin/pip install pillow==11.3.0
	curl https://fonts.gstatic.com/s/dmsans/v17/rP2tp2ywxg089UriI5-g4vlH9VoD8CnsqpG40F9JadbnoEwAIpthTg.ttf --output .bin/dm-sans.ttf

run: # Build the site and run the server locally, for testing things out
	make cards
	(cd frontend && ../.bin/elm make src/Main.elm --output=main.js)
	(cd backend && cargo run)

build: # Build and optimize for production
	make cards
	(cd frontend && ../.bin/elm make src/Main.elm --output=main.js --optimize)
	(cd backend && cargo build --release)

test:
	(cd backend && cargo test)

cards: # Generate the card faces
	.venv/bin/python scripts/generate-cards.py
