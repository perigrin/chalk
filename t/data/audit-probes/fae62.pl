my $r = eval { eval { die "in\n" }; "v:$@" }; print $r;
