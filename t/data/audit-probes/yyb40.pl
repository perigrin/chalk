my @a=(1,2); my $o={l=>\@a}; sub z { $o->{l}[1]=7 } for my $x (@a) { z(); print $x } print "\n";
