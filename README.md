# Zig HTTP Server

Implementation of a subset of the HTTP/1.1 protocol using Zig and the Std Library for socket connection. By using the [codecrafters](https://codecrafters.io/) C course on Building a HTTP server as a reference.

## Description

The root responses with an 200 OK empty response. You can echo something from the server by calling **/echo/\<some_string>**. One can read and write files from and to the Server by calling **/files/\<filename>** with a GET or POST request. The **files** directory is routed to /files endpoint by default. NO compression is implemented yet.

## Getting Started

### Dependencies

Make sure you have a working installation of [zig](https://ziglang.org/) version **0.13.0** on your system.

### Installing

Clone the github repo and enter the root directory.
```bash
git clone https://github.com/nico1645/zig-http-server.git
```
Test the application by running.
```bash
zig build test
```

### Running/Building server

Start the HTTP server on 127.0.0.1 with port 4221 by running.
```bash
zig build run
```
Building with.
```bash
zig build
```
Running the executable, read the help page for arguments infos.
```bash
./zig-out/bin/zig-http-server help
```

## Authors

Name: Nico Bachmann
Email: [contact@famba.me](mailto:contact@famba.me)

## License

This project is licensed under the GNU GPL License - see the LICENSE file for details
