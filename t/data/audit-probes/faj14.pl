my $o={a=>1,b=>2}; $_*=2 for @$o{qw(a b)}; print "$o->{a}$o->{b}\n";
