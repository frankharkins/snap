install: # Install everything needed to build this project
	mkdir -p .bin

	rustup target add x86_64-unknown-linux-musl

	echo "Installing elm..."
	curl -L -o elm.gz https://github.com/elm/compiler/releases/download/0.19.1/binary-for-linux-64-bit.gz
	gunzip elm.gz
	chmod +x elm
	mv elm .bin/

	python3 -m venv .venv
	.venv/bin/pip install pillow==11.3.0
	curl https://fonts.gstatic.com/s/dmsans/v17/rP2tp2ywxg089UriI5-g4vlH9VoD8CnsqpG40F9JadbnoEwAIpthTg.ttf --output .bin/dm-sans.ttf

	npm install uglify-js --global
	npm install minify --global

run: # Build the site and run the server locally, for testing things out
	make cards
	(cd frontend && ../.bin/elm make src/Main.elm --output=main.js)
	(sed -i -e 's|929b8e9b3748f2e04edf|ws://localhost:3030|' frontend/main.js)
	(cd backend && cargo run)

build: # Build and optimize for production
	make cards

	(cd frontend && ../.bin/elm make src/Main.elm --output=main.js --optimize)
	(sed -i -e 's|929b8e9b3748f2e04edf|wss://snap-image.onrender.com|' frontend/main.js)
	uglifyjs frontend/main.js --compress 'pure_funcs=[F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9],pure_getters,keep_fargs=false,unsafe_comps,unsafe' | uglifyjs --mangle --output frontend/main.min.js
	minify frontend/index.html > frontend/index.min.html
	minify frontend/main.css > frontend/main.min.css

	(cd backend && cargo build --release --target x86_64-unknown-linux-musl)

	docker build --no-cache . -t "frankharkins/personal:snap"
	rm frontend/*.min.*

test:
	(cd backend && cargo test)

cards: # Generate the card faces
	.venv/bin/python scripts/generate-cards.py
