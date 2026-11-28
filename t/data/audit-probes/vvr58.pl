my %h = (a=>1,b=>2); my $r = \$h{a}; my %g = %h; $g{a} = 9; print "$$r\n";
