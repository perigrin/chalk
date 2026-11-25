my @a=(1,2); my $r=\@a; $_++ for @$r; $_++ for $r->@*; my %h=(l=>[5]); $_++ for @{$h{l}}; my ($c,@d,@e)=(1,(7),()); $_++ for $c ? @a : @d; print "@a$h{l}[0]\n";
