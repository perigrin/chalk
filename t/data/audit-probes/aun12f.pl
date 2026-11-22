our @st; sub pu { push @st, $_[0]; scalar @st } my $s = join ",", pu("a"), scalar(@st), pu("b"), scalar(@st); print "$s\n";
