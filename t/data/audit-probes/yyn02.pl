eval { die { code => 5 } }; print $@->{code}, ref($@); eval { die [1,2] }; print "@{$@}"; eval { die bless {}, "E" }; print ref($@), "\n";
