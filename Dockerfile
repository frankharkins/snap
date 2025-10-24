FROM --platform=linux/amd64 gcr.io/distroless/static-debian12

WORKDIR /usr/app

ADD ./backend/target/x86_64-unknown-linux-musl/release/snap-backend ./backend/snap-backend
ADD ./frontend/images ./frontend/images
ADD ./frontend/index.min.html ./frontend/index.html
ADD ./frontend/main.min.css ./frontend/main.css
ADD ./frontend/main.min.js ./frontend/main.js

WORKDIR /usr/app/backend

CMD [ "./snap-backend" ]
