local $SIG{__WARN__} = sub { print "W:", $_[0] =~ /uninitialized/ ? "uninit" : "other", "\n" }; use warnings; my $u; my $s = "a" . $u;
