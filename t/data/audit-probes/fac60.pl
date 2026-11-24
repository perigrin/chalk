my $o={m=>{a=>1}}; my %c=%{$o->{m}}; $o->{m}{a}=9; $c{b}=1; print "$c{a}", exists $o->{m}{b}?1:0, "\n";
