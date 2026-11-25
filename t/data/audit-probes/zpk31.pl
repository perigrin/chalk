our $n=0; sub inc { $n++ } my $nm="inc"; &$nm() for 1..2; print "$n\n";
