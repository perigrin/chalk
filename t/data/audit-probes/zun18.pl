eval { eval { die "in\n" }; die "re: $@" }; print $@;
