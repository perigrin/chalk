my $s = "abc"; my $n = $s =~ s/(.)/uc($1)/ge; print "$n$s\n";
