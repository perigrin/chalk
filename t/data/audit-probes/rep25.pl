sub cfg { my $c = shift; return $c->{opt}{verbose} ? 1 : 0 } my %c; cfg(\%c); print join(",", keys %c), "\n";
