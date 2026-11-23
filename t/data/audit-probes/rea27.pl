my @a=(1,2,3); my $t=0; for (@a) { $t += $_; $_ = 0 if $_ == 2 } print "$t @a\n";
