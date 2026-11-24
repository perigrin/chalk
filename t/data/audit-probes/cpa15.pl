my %h=(a=>1); my %c=%h; my $s = sub { $c{a}=5 }; $s->(); print "$h{a} $c{a}\n";
