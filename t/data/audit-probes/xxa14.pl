sub f { $_ .= "!" for @_ } my %h=(a=>1,b=>2); f(values %h); print join(",", map {$h{$_}} sort keys %h), "\n";
