my $r=eval { eval { die "a\n" }; "v:$@" }; print $r;
