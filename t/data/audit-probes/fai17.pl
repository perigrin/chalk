my ($a,$b)=(1,2); sub st { $_[0]=9 } my $c=1; st($c ? $a : $b); print "$a$b\n";
