my %h=(a=>1); my $s = sub { $h{a} }; my %c=%h; $c{a}=2; print $s->(), " $c{a}\n";
