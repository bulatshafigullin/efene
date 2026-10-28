EFENE ?= ../../_build/default/bin/efene
ORM := ../orm/src
DB ?= efene_shop_example

.PHONY: all deps build db run serve clean

all: build

# fetch and compile postgrex and cowboy with mix
deps:
	mix deps.get
	mix compile

# the orm's #q compiler extension first, then shop_api.fn and every efene
# module it uses, looked up in src (the directory of shop_api.fn) and the orm
build:
	mkdir -p ebin
	$(EFENE) beam $(ORM)/fn_ext_val_atom_q.fn ebin
	ERL_FLAGS="-pa $(CURDIR)/ebin" $(EFENE) beam --root $(ORM) src/shop_api.fn ebin

db:
	createdb $(DB) 2>/dev/null || true

# start the server, make example requests and stop
run: build db
	SHOP_DATABASE=$(DB) mix run -e ':code.add_patha(~c"ebin"); :shop_api.demo()'

# keep the server running, try it with curl
serve: build db
	SHOP_DATABASE=$(DB) mix run --no-halt -e ':code.add_patha(~c"ebin"); :shop_api.start()'

clean:
	rm -rf ebin
