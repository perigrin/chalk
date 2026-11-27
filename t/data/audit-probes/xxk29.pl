my $s = "a.b"; my @p = map { s/\./!/r } ($s, $s); $s =~ s/\./?/; print "@p$s\n";
