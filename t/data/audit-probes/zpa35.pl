my %h=(a=>1,b=>2); sub inc { $_++ for @_ } inc(@h{qw(a b)}); print "$h{a}$h{b}\n";
