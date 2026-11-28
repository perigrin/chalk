my %h = (b=>2, a=>1); my @o = map { "$_=$h{$_}" } sort { $h{$a} <=> $h{$b} } keys %h; print "@o\n";
