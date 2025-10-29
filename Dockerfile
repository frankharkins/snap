FROM --platform=linux/amd64 gcr.io/distroless/static-debian12

WORKDIR /usr/app

ADD ./backend/target/x86_64-unknown-linux-musl/release/snap-backend ./backend/snap-backend
ADD ./frontend/build ./frontend

WORKDIR /usr/app/backend

CMD [ "./snap-backend" ]
