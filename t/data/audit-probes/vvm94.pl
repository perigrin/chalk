our %h = (a=>1); { no strict 'refs'; local ${"h"}{a} = 2; print $h{a} } print $h{a}, "\n";
