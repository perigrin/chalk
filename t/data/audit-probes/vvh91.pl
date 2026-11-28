local $@ = "pre"; eval { die "in\n" }; print $@;
