eval { die { code => 7 } }; print ref($@), " ", (ref $@ ? $@->{code} : "str"), "\n";
