my %h = (a=>1,b=>2); my $r = \$h{a}; %h = reverse %h; print "$$r\n";
