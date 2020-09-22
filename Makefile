ZIG ?= zig
simple_client: simple_client.zig
	$(ZIG) build-exe -target native simple_client.zig -lc -ljack

clean:
	rm -f simple_client *.o a.out
