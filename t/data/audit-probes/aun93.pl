our $g=1; eval { local $g = 2; my $s = "a"; my $n = sprintf("%s", $s); die { c => 3 } }; print "$g $@->{c}\n";
