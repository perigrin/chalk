our @g=(1,2); my $r = \@g; my @c = (@g); push @$r, 3; print "@c|@g\n";
