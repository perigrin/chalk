my %h = (a=>1,b=>2); my $r = \$h{a}; @h{qw(a b)} = @h{qw(b a)}; print "$$r$h{a}\n";
