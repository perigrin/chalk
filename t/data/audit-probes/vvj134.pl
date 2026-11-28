my %h = (a=>1,b=>2); my %s = %h{qw(a)}; my @kv = %h{qw(b)}; print join(",", %s), "@kv\n";
