eval { my @a = (1); for (@a) { die { c => 7 } } }; print ref($@) ? $@->{c} : "s", "\n";
