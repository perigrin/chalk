our %h = (a=>1); { no strict 'refs'; local %{"h"} = (b=>2); print join(",", keys %h), ";" } print join(",", keys %h), "\n";
