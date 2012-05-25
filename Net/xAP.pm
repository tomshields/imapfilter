#!/usr/local/bin/perl
#
# Copyright (c) 1997-1998 Kevin Johnson <kjj@pobox.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: xAP.pm,v 1.1 1998/12/01 02:13:52 ts Exp $

require 5.004;

package Net::xAP;

use strict;

=head1 NAME

Net::xAP - An interface to the protocol beneath IMAP, ACAP, and ICAP.

B<WARNING: This code is in alpha release.  Expect the interface to change.>

=head1 SYNOPSIS

C<use Net::xAP;>

=head1 DESCRIPTION

This base class implements the protocol that is common across the
IMAP, ACAP, ICAP protocols.  It provides the majority of the interface
to the network calls and implements a small amount of glue to assist
in implementing interfaces to this protocol family.

=head1 METHODS

=cut

use Exporter ();

use IO::Socket;
use Carp;
use vars qw(@EXPORT_OK);

@EXPORT_OK = qw($xAP_ATOM $xAP_ASTRING $xAP_PARENS $xAP_STRING);
use vars qw($VERSION $SEQUENCE
	    @ISA @EXPORT_OK
	    $xAP_ATOM $xAP_ASTRING $xAP_PARENS $xAP_STRING);

@ISA = qw(Exporter);

$VERSION = '0.01';

$SEQUENCE = 0;

my $Debug = 0;

$xAP_ATOM = 0;
$xAP_ASTRING = 1;
$xAP_PARENS = 2;
$xAP_STRING = 3;

=head1 METHODS

=head2 new ($host, $peerport [, %options])

Create a new instance of Net::xAP and returns a reference to the
object.

The C<$host> parameter is the name of the host to contact.

The C<$peerport> parameter is the tcp port to connect to. The
parameter should be in the syntax understood by
C<IO::Socket::INET-E<gt>new>).

C<%options> specifies any options to use. Currently, the only option
that C<Net::xAP> uses is C<Debug>.  All of the options are passed to a
call to C<IO::Socket::INET-E<gt>new>.

=cut

sub new {
  my $class = shift;
  my $type = ref($class) || $class;
  my $host = shift;
  my $peerport = shift;
  my %options = @_;
  
  $options{Debug} ||= $Debug;
  
  my $self = bless {}, $class;
  
  $self->{Options}  = {%options};
  
  $self->{Connection} = IO::Socket::INET->new(PeerAddr => $host,
					      PeerPort => $peerport,
					      Proto => 'tcp',
					      %options) or return undef;
  $self->{Connection}->autoflush(1);

  $self->{Pending} = ();
  $self->{Sequence} = 0;
  
  return $self;
}

=head2 command ($callback, $command [, @args])

The C<command> is used to send commands to the connected server and to
setup callbacks for subsequent use by the C<response> method.

The C<$callback> parameter should be a reference to a subroutine that
will be called when input is received.  This callback is responsible
for processing any of the responses from the server that pertain the
given command.

C<@args> is a list of C<$type>-C<$value> pairs.  The C<$type> says
what type of data type to use for C<$value>.  The mechanism is used to
control the encoding necessary to pass the command arguments to the
server.

The following C<$type>s are understood:

=over 2

=item * $xAP_ATOM

The data will sent raw to the server.

=item * $xAP_ASTRING

The data will be sent to the server as an atom, a quoted string, or a
literal depending on the content of C<$value>.

=item * $xAP_PARENS

The data in C<$value> will be interpreted as an array reference and be
sent inside a pair of parentheses.

=item * $xAP_STRING

The data will be sent to the server as either a quoted string or
literal depending on the content of C<$value>.

=back

=cut

sub command {
  my $self = shift;
  my $callback = shift;
  my $cmd = shift;

  return undef unless ($#_ % 2); # TODO: need an error msg here

  $self->{Sequence}++;

  my $str = "$self->{Sequence} $cmd";

  while (my ($type, $value) = splice @_, 0, 2) {
    $str .= ' ';
    if (($type == $xAP_ASTRING) || ($type == $xAP_STRING)){
      my $astring =
	($type == $xAP_ASTRING) ?
	  $self->as_astring($value) :
	    $self->as_string($value);
      if (ref($astring) eq 'ARRAY') {
	$str .= "{" . $astring->[0] . "}";
	push @{$self->{PendingLiterals}}, $astring;
      } else {
	$str .= $astring;
      }
    } elsif ($type == $xAP_ATOM) {	# maybe should check for non-ATOMCHARs
      $str .= $value;
    } elsif ($type == $xAP_PARENS) {
      $str .= '(' . join(' ', @{$value}) . ')';
    } else {
      croak "unknown argument type: $type";
    }
  }
  return undef unless (($str eq '') || $self->send_command($str));

  $self->{LastCmdTime} = time;

  $self->{Pending}{$self->{Sequence}} = $callback;

  return $self->response if (defined($self->{Options}{Synchronous}) &&
			     $self->{Options}{Synchronous});
  return $self->{Sequence};
}

=head2 parse_line

=cut

sub parse_line {
  my $self = shift;
  my $str = shift;
  my @list;
  my @stack = ([]);

  my $pos = 0;
  my $len = length($str);
  while ($pos < $len) {
    my $c = substr($str, $pos, 1);
    if ($c eq ' ') {
      $pos++;
    } elsif ($c eq '(') {
      push @{$stack[-1]}, [];
      push @stack, $stack[-1]->[-1];
      $pos++;
    } elsif ($c eq ')') {
      pop(@stack);
      $pos++;
    } elsif (substr($str, $pos) =~ /^(\"(?:[^\\\"]|\\\")*\")[\s\)]?/) {
				# qstring
      push @{$stack[-1]}, $1;
      $pos += length $1;
    } elsif (substr($str, $pos) =~ /^\{(\d+)\}/) { # literal
      $pos += length($1) + 2;
				# soak up the literal payload
      push @{$stack[-1]}, substr($str, $pos, $1);
      $pos += $1;
    } elsif (substr($str, $pos) =~ /^([^\x00-\x1f\x7f\(\)\{\s\"]+)[\s\)]?/) {
				# atom
      push @{$stack[-1]}, $1;
      $pos += length $1;
    } else {
      croak "parse_line: eeeek! bad parse at position $pos [$str]\n";
    }
  }

  return @{$stack[0]};
}

=head2 as_astring

=cut

sub as_astring {
  my $self = shift;
  my $str = shift;
  my $type = 0;

  my $len = length $str;

  if (($str =~ /[\x00\x0a\x0d\"\\\x80-\xff]/) || ($len > 1024)) { # literal
    return [($len, $str)];
  } elsif ($str =~ /[\x01-\x20\x22\x25\x28-\x2a\{]/) { # qstring
    return "\"$str\"";
  } elsif ($str eq '') {
    return '""';
  } else {
    return $str;
  }
}

=head2 as_string

=cut

sub as_string {
  my $self = shift;
  my $str = shift;
  my $type = 0;

  my $len = length $str;

  if (($str =~ /[\x00\x0a\x0d\"\\\x80-\xff]/) || ($len > 1024)) { # literal
    return [($len, $str)];
  } elsif ($str eq '') {
    return '""';
  } else {
    return "\"$str\"";
  }
}

=head2 send_command

=cut

sub send_command {
  my $self = shift;
  my $str = shift;
  my $len = length $str;

  $self->debug_print(1, $str) if $self->debug;
  (($self->{Connection}->syswrite($str, $len) == $len) &&
   ($self->{Connection}->syswrite("\r\n", 2) == 2))
    or return undef;
}

=head2 response

=cut

sub response {
  my $self = shift;

  # Currently returns undef if there's nothing pending. This isn't the
  # technically correct thing to do, but it's probably ok for now.
  # At some point, it should do a select on the socket and reap
  # unsolicited responses if any are present and pass them through
  # default_callback.
  return undef unless scalar keys %{$self->{Pending}};

  my $response;
  while (1) {
    my $list = $self->getline;
    $self->debug_print(0, join(' ', @{$list})) if $self->debug;
    
    my $found_one = 0;
    if ($list->[0] eq '+') {
      my $lit = pop(@{$self->{PendingLiterals}});
      (($self->{Connection}->syswrite($lit->[1], $lit->[0]) == $lit->[0]) &&
       ($self->{Connection}->syswrite("\r\n", 2) == 2))
	or croak "eek! can't send literal payload";
      $found_one++;
    } else {
      # rifle through the callbacks of the pending commands and ask each
      # of them if the resposne belongs to them.  If it does, then stop
      # looking for a match.
      for my $seq (sort { $a <=> $b } keys %{$self->{Pending}}) {
	my $ret = &{$self->{Pending}{$seq}}($list);
	if ($ret == 0) {
	  # callback didn't claim it
	} elsif ($ret < 0) {
	  # maybe need to call an error callback or something...
	} else {		# the callback returned an object
	  $found_one++;
	  $self->debug_print(0, "callback $seq") if $self->debug;
	  $response = $ret;	# TODO: we should check for an actual object
	  last;
	}
      }
    }
    # if none of the pending command callbacks claimed the response then
    # pass it to a default callback.
    if (!$found_one && defined($self->{DefaultCallback})) {
      if (&{$self->{DefaultCallback}}($list)) {
	$self->debug_print(0, "default callback") if $self->debug;
      } else {
	carp "response not claimed by a callback: [", join(' ', @{$list}), "]";
      }
    }
    last if (($list->[0] =~ /^\d+$/) && ($list->[1] =~ /^OK|NO|BAD$/i));
  }
  my $tag = $response->tag;
  delete $self->{Pending}{$tag} if defined($self->{Pending}{$tag});
    
  return $response;
}

=head2 getline

Gets one line of data from the server, parses it into a list of fields
and returns a reference to the list.  C<getline> uses the
C<parse_line> method to do the parsing.

=cut

sub getline {
  my $self = shift;
  my @list;
  my $pstr;

  while (1) {
    my $str = $self->{Connection}->getline or return undef;
    $str =~ s/\r?\n$//;
    # push @list, $self->parse_line($str);
    if ($str =~ /\{(\d+)\}$/) {
      # if it's a literal then read in the payload and replace the {\d+}
      # with the payload.
      my $amt = $1;
      my $morestr;
      $self->{Connection}->read($morestr, $amt) == $amt
	or return undef;
      $str .= $morestr;
      # $list[-1] = $morestr;
      $pstr .= $str;
    } else {
      $pstr .= $str;
      last;
    }
  }
  push @list, $self->parse_line($pstr);
  return [@list];
}

=head2 last_command_time

Return what time the most recent command was sent to the server.  It
returns value as a C<time> integer.

=cut

sub last_command_time { return $_[0]->{LastCmdTime} }

=head2 connection

Returns the connection object being used by the object.

=cut

sub connection { return $_[0]->{Connection} }

=head2 sequence

Returns the sequence number of the last command issued to the server.

=cut

sub sequence { $_[0]->{Sequence} }

=head2 next_sequence

Returns the sequence number that will be assigned to the next command issued.

=cut

sub next_sequence { $_[0]->{Sequence} + 1 }

=head2 pending

Returns a list of sequence numbers for the commands that are still
awaiting a complete response from the server.  This will also include
any recent commands issued without corresponding C<response> methods
called. C<NEEDS TO BE REWORDED>

The list is sorted numerically.

=cut

sub pending { sort { $a <=> $b } keys %{$_[0]->{Pending}} }

###############################################################################

=head2 debug ([$boolean])

Returns the value of the debug flag for the object.

If C<$boolean> is specified, set the debug state to the given value.

=cut

sub debug {
  $_[0]->{Options}{Debug} = $_[1] if (defined($_[1]));
  return $_[0]->{Options}{Debug};
}

=head2 debug_text ($text)

A stub method intended to be overridden by subclasses.  It is intended
to provide subclasses to make alterations to C<$text> for use by the
C<debug_print> method.  The base-class version does no alteration of
C<$text>.

=cut

sub debug_text { $_[2] }

=head2 debug_print($direction, $text)

Prints C<$text> to C<STDERR>. The parameter C<$direction> is used to
notate what direction the call is interested in - C<0> for data being
sent to the server, C<1> for data coming from the server.

This mechanism might change in the future...

=cut

sub debug_print {
  print(STDERR
	$_[1]?'->':'<-',
	" $_[0]",
	" [", $_[0]->debug_text($_[1], $_[2]), "]\n");
}

###############################################################################
package Net::xAP::Response;

=head1 Response Objects

A response object is the data type returned by the C<response> method.
A few convenience routines are provided at the Net::xAP level that are
likely to be common across several protocols.

=head2 new

=cut

sub new {
  my $class = shift;
  my $type = ref($class) || $class;

  my $self = bless {}, $class;

  $self->{Sequence} = 0;
  $self->{CmdStatus} = '';
  $self->{StatusText} = '';

  return $self;
}

=head2 tag

Returns the tag associated with the response object.

=cut

sub tag { return shift->{Sequence} }

=head2 status

Returns the command status associated with the response object.  This
will be C<OK>, C<NO>, or C<BAD>.

=cut

sub status { return shift->{CmdStatus} }

=head2 status_text

Returns the human readable text assocated with the status of the
response object.

This will typically be overridden by a subclass of the C<xAP> class to
handle things like status codes.

=cut

sub status_text { return shift->{StatusText} }

=head2 status_code

=cut

sub status_code { return shift->{StatusCode} }

=head2 parse_status (@list)

=cut

sub parse_status {
  my $self = shift;
  my $list = shift;
  my @list2 = @{$list};

  $self->{Sequence} = shift(@list2);
  $self->{CmdStatus} = uc(shift(@list2));

  my $str = join(' ', @list2);
  $str =~ /^(?:\[([^\]]+)\] )?(.*)$/;
  $self->{StatusCode} = uc($1 || '');
  $self->{StatusText} = $2;
}

###############################################################################

=head1 CAVEATS

With only a few exceptions, the methods provided in this class are not
intended to be used by end-programmers.  They are intended to be used
by implementers of protocols that use the class.

=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@pobox.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1997 Kevin Johnson <kjj@pobox.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
