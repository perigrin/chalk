my $s=""; my @l=(1,2,3); my @m = map { $s .= $_; $_ * 2 } @l; print "$s @m\n";
