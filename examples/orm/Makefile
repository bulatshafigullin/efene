EFENE ?= ../../_build/default/bin/efene
DB ?= efene_orm_example

.PHONY: all deps build db run clean

all: build

# fetch and compile the postgrex driver with mix
deps:
	mix deps.get
	mix compile

# the #q compiler extension is built first and put in the compiler's code path,
# then demo.fn and every efene module it uses (src is the import root)
build:
	mkdir -p ebin
	$(EFENE) beam src/fn_ext_val_atom_q.fn ebin
	ERL_FLAGS="-pa $(CURDIR)/ebin" $(EFENE) beam src/demo.fn ebin

db:
	createdb $(DB) 2>/dev/null || true

run: build db
	ORM_DATABASE=$(DB) mix run -e ':code.add_patha(~c"ebin"); :demo.main()'

clean:
	rm -rf ebin
