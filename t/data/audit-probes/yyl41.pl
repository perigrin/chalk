my $s = "aXbXc"; my @parts; while ($s =~ /\G([^X]*)(?:X|$)/gc) { push @parts, $1; last if pos($s) >= length $s } print join("|", @parts), "\n";
