my %h=(a=>1); my $t = !%h; %h=(); my $u = !%h; print $t?1:0, $u?1:0, "\n";
