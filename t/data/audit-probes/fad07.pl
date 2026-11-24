our $g=1; sub f { local $g=2; die {c=>7} } eval { f() }; print "$g $@->{c}\n";
