my %h=(a=>1); my $o={k=>\%h}; my %c=%{$o->{k}}; $h{a}=9; print "$c{a}\n";
