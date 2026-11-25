my $c=0; sub cnt { return ++$c } my @r=(cnt(), cnt(), cnt()); my %h=(a=>cnt(), b=>cnt()); print "@r $h{a}$h{b}\n";
