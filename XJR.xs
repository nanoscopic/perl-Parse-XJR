// JEdit mode Line -> :folding=indent:mode=c++:indentSize=2:noTabs=true:tabSize=2:
#include "EXTERN.h"
#define PERL_IN_HV_C
#define PERL_HASH_INTERNAL_ACCESS

#include "perl.h"
#include "XSUB.h"
#include<xjr-machine.h>
#include<xjr-node.h>
#include<xjr-mempool.h>

typedef struct keyquery_s keyquery;
struct keyquery_s {
  xjr_key_arr *arr;
  SV *perlob;
  int curpos;
  keyquery *next;
};

typedef struct xjr_pnode_s xjr_pnode;
struct xjr_pnode_s {
  xjr_node *node;
  char *text;
  char doFree;
};
xjr_pnode *xjr_pnode__new( xjr_node *node, char *text, char doFree ) {
  xjr_pnode *pnode = (xjr_pnode *) calloc( sizeof( xjr_pnode ), 1 );
  pnode->node = node;
  pnode->text = text;
  pnode->doFree = doFree;
  return pnode;
}
xjr_pnode *xjr_pnode__delete( xjr_pnode *pnode ) {
  if( pnode->doFree ) free( pnode->text );
  free( pnode );
}

keyquery *head = NULL;
keyquery *keyquery__new( xjr_key_arr *arr, SV *perlob ) {
  keyquery *newk = ( keyquery * ) malloc( sizeof( keyquery ) );
  newk->next = head;
  newk->arr = arr;
  newk->curpos = 0;
  newk->perlob = perlob;
  head = newk;
  return newk;
}
keyquery *keyquery__find( SV *perlob ) {
  keyquery *curQ = head;
  while( curQ ) {
    if( curQ->perlob == perlob ) return curQ;
    curQ = curQ->next;
  }
  return NULL;
}
void keyquery__delete( keyquery *toDel ) {
  keyquery *curQ = head;
  keyquery *prev = NULL;
  while( curQ ) {
    keyquery *next = curQ->next;
    if( curQ == toDel ) {
      xjr_key_arr__delete( toDel->arr );
      free( toDel );
      if( prev ) {
        prev->next = next;
      }
      else {
        head = next;
      }
      break;
    }
    prev = curQ;
    curQ = curQ->next;
  }
}

SV *fakeStr( char *out, int len ) {
  SV *sv;
  sv = newSViv(1);
  sv_upgrade(sv, SVt_PV);
  SvPOK_on(sv);
  SvPV_set(sv, out);
  SvLEN_set(sv, len+1);
  SvCUR_set(sv, len);
  SvFAKE_on(sv);
  SvREADONLY_on(sv);
  return sv;
}

void sethash( xjr_node *node, char *key1, int keylen1, SV *hashsv ) {
  HV *hash = ( HV * ) SvRV( hashsv );
  
  xjr_node *sub;
  
  char l1 = key1[0];
  if( l1 == '+' ) {
    key1++;
    keylen1--;
    printf("Appending a new %.*s\n", keylen1, key1 );
    sub = xjr_node__new( (xjr_mempool *)0, strdup(key1), keylen1, node );
    sub->flags |= FLAG_DYNNAME;
  }
  else if( l1 == '|' ) {
    key1++;
    keylen1--;
    sub = xjr_node__get( node, key1, keylen1 );
  }
  else {
    sub = xjr_node__get( node, key1, keylen1 );
    if( sub ) {
      #ifdef DEBUG
      printf("Removing all nodes named %.*s\n", keylen1, key1 );
      #endif
      xjr_node__removeall( sub->parent, key1, keylen1 );
    }
    sub = xjr_node__new( (xjr_mempool *)0, strdup(key1), keylen1, node );
    sub->flags |= FLAG_DYNNAME;
  }
  
  hv_iterinit( hash );
  HE *curHE = hv_iternext( hash );
  while( curHE ) {
    int keylen;
    char *key = hv_iterkey( curHE, &keylen );
    #ifdef DEBUG
    printf("Key: %.*s\n", keylen, key );
    #endif
    SV *valsv = hv_iterval( hash, curHE );
    if( SvROK( valsv ) ) {
      int type = SvTYPE(SvRV(valsv));
      if( type == SVt_PVHV ) {
        sethash( sub, key, keylen, valsv );
      }
    }
    else { // scalar value
      //sub->val = SvPV( valsv, vallen );
      //sub->vallen = vallen;
      xjr_node *valnode;
      
      char s1 = key[0];
      if( s1 == '+' ) {
        key++;
        keylen--;
        valnode = xjr_node__new( (xjr_mempool *)0, strdup(key), keylen, sub );
      }
      else if( s1 == '#' ) { // # denotes an attribute; because @ will denote for each
        key++;
        keylen--;
        valnode = xjr_node__get( sub, key, keylen );
        if( !valnode ) {
          valnode = xjr_node__new( (xjr_mempool *)0, strdup(key), keylen, sub );
        }
        valnode->flags |= FLAG_ATT;
      }
      else {
        valnode = xjr_node__get( sub, key, keylen );
        if( !valnode ) {
          valnode = xjr_node__new( (xjr_mempool *)0, strdup(key), keylen, sub );
        }
      }
      valnode->val = SvPV( valsv, valnode->vallen );
      #ifdef DEBUG
      printf("Setting %.*s to %.*s\n", keylen, key, valnode->vallen, valnode->val );
      #endif
    }
    curHE = hv_iternext( hash );
  }
}

SV *tied_node( SV *data ) {
  HV *hash = newHV();
  SV *tie = newRV_noinc( data );//_noinc
  
  // make the hash magical
  //hv_magic(hash, (GV*)tie, PERL_MAGIC_regdata);
  sv_magic(hash, tie, PERL_MAGIC_tied, NULL, 0);
  
  // create an rv, and bless the it into the class
  HV *stash = gv_stashpv("Parse::XJR::Node", GV_ADD);
  SV *rv = newRV_noinc( hash );
  
  sv_bless( rv, stash );
  
  MAGIC *mgtable = SvMAGIC( hash );
  
  return rv;
}

MODULE = Parse::XJR         PACKAGE = Parse::XJR

SV *
c_parse(textsv,copyStr,mixedsv)
  SV *textsv
  SV *copyStr
  SV *mixedsv
  CODE:
    STRLEN len;
    char *text;
    xjr_node *root;
    text = SvPV(textsv, len);
    xjr_node__disable_mempool();
    int doCopy = SvIV( copyStr );
    text = strndup( text, len );
    
    int mixed = SvIV( mixedsv );
    //void *parse_full( xjr_mempool *pool, char *input, int len, xjr_node *root, int *endpos, int returnToRoot, int mixedMode )
    root = parse_full( (xjr_mempool *) 0, text, len, 0, 0, 0, mixed );
    //root = parse( (xjr_mempool *) 0, text, len );
    xjr_pnode *pnode = xjr_pnode__new( root, text, doCopy );
    RETVAL = tied_node( newSVuv( PTR2UV( pnode ) ) );
  OUTPUT:
    RETVAL

MODULE = Parse::XJR         PACKAGE = Parse::XJR::Node

#define cast_magic( source, dest_type ) INT2PTR( dest_type, SvIV( SvRV( SvMAGIC( SvRV( source ) )->mg_obj ) ) );  


SV *
FIRSTKEY( nodesv )
  SV *nodesv
  PREINIT:
    xjr_pnode *pnode;
    xjr_node *node;
  CODE:
    pnode = INT2PTR( xjr_node *, SvUV( SvRV( nodesv ) ) );
    node = pnode->node;
    xjr_key_arr *arr = xjr_node__getkeys( node );
    keyquery *kq;
    if( kq = keyquery__find( nodesv ) ) {
      keyquery__delete( kq );
    }
    
    if( arr->count > 0 ) {
      RETVAL = newSVpv( arr->items[0], arr->sizes[0] );
    }
    else {
      RETVAL = &PL_sv_undef;
    }
    if( arr->count > 1 ) {
      kq = keyquery__new( arr, nodesv );
      kq->curpos++;
    }
    else {
      xjr_key_arr__delete( arr );
    }
  OUTPUT:
    RETVAL

SV *
NEXTKEY( nodesv, prevkey )
  SV *nodesv
  SV *prevkey
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    //printf("Nextkey called\n");
    pnode = INT2PTR( xjr_node *, SvUV( SvRV( nodesv ) ) );
    node = pnode->node;
    keyquery *kq;
    if( kq = keyquery__find( nodesv ) ) {
      int curpos = kq->curpos++;
      //printf("Curpos = %i ( count=%i)\n", curpos, kq->arr->count );
      xjr_key_arr *arr = kq->arr;
      char *key = arr->items[curpos];
      int keylen = arr->sizes[curpos];
      //printf("Returning %.*s\n", keylen, key );
      RETVAL = newSVpv( key, keylen );
      if( curpos >= ( arr->count -1 ) ) {
        keyquery__delete( kq );
      }
    }
    else {
      RETVAL = &PL_sv_undef;
    }    
  OUTPUT:
    RETVAL

void
parse(nodesv,textsv)
  SV *nodesv
  SV *textsv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    STRLEN len;
    char *text;
    xjr_node *root;
    text = SvPV(textsv, len);
    parse_onto( (xjr_mempool *)0, text, len, node );

void
c_setval( nodesv, keysv, valsv )
  SV *nodesv
  SV *keysv
  SV *valsv
  PREINIT:
    xjr_node *node;
    xjr_node *sub;
    xjr_pnode *pnode;
    STRLEN keylen;
    char *key;
    STRLEN vallen;
    char *val;
    char *dup;
    char *dup2;
  CODE:
    pnode = INT2PTR( xjr_pnode *, SvUV( SvRV( nodesv ) ) );
    node = pnode->node;
    
    key = SvPV( keysv, keylen );
    val = SvPV( valsv, vallen );
    
    if( key[0] == '+' ) { // this only really makes sense as adding to an array of these things
      // TODO; do this correctly; fetching a node if it exists, then adding another one on
      dup = malloc( keylen - 1 );
      memcpy( dup, key + 1, keylen - 1 );
      sub = xjr_node__new( (xjr_mempool *)0, dup, keylen-1, node );
    }
    else {
      sub = xjr_node__get(node, key, keylen);
      if( !sub ) {
        dup = malloc( keylen );
        memcpy( dup, key, keylen );
        sub = xjr_node__new( (xjr_mempool *)0, dup, keylen, node );
      }
    }
    
    dup2 = malloc( vallen );
    memcpy( dup2, val, vallen );
    sub->val = dup2;
    sub->vallen = vallen;
    sub->flags |= ( FLAG_DYNNAME | FLAG_DYNVAL );
    
void
c_sethash( mgObjSv, keysv, hashsv )
  SV *mgObjSv
  SV *keysv
  SV *hashsv
  PREINIT:
    xjr_node *node;
    xjr_node *sub;
    xjr_pnode *pnode;
  CODE:
    pnode = INT2PTR( xjr_pnode *, SvUV( SvRV( mgObjSv ) ) );
    node = pnode->node;
    
    STRLEN keylen;
    char *key;
    key = SvPV(keysv, keylen );
    sethash( node, key, keylen, hashsv );

void
makeroot( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    node->flags |= FLAG_ISROOT;

void
c_free_tree( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    MAGIC *mg = ( (XPVMG*) SvRV( nodesv )->sv_any )->xmg_u.xmg_magic;
    if( mg ) {
      pnode = INT2PTR( xjr_pnode *, SvUV( SvRV( mg->mg_obj ) ) );
      node = pnode->node;
      if( node && node->flags & FLAG_ISROOT ) {
        //printf("Attempting to free %p\n", node );
        xjr_node__delete( node );
      }
      xjr_pnode__delete( pnode );
    }    

SV *
name( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    val = xjr_node__name(node, &len);
    RETVAL = newSVpv( val, len );
  OUTPUT:
    RETVAL

SV *
value( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    val = xjr_node__value(node, &len);
    RETVAL = newSVpv( val, len );
  OUTPUT:
    RETVAL

SV *
xjr( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
    xml_output *output;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    output = xjr_node__xml( node );
    val = xml_output__flatten( output, &len );
    xml_output__delete( output );
    RETVAL = fakeStr( val, len );
  OUTPUT:
    RETVAL

SV *
outerxjr( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
    xml_output *output;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    output = xjr_node__outerxml( node );
    val = xml_output__flatten( output, &len );
    xml_output__delete( output );
    RETVAL = fakeStr( val, len );
  OUTPUT:
    RETVAL

void
dump( nodesv, depth )
  SV *nodesv
  SV *depth
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
    xml_output *output;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    xjr_node__dump( node, SvIV( depth ) );

SV *
isflag( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
    xml_output *output;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    if( node->flags & FLAG_FLAG ) {
      RETVAL = newSVuv( 1 );
    }
    else {
      RETVAL = &PL_sv_undef;
    }
  OUTPUT:
    RETVAL

SV *
isatt( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
    xml_output *output;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    if( node->flags & FLAG_ATT ) {
      RETVAL = newSVuv( 1 );
    }
    else {
      RETVAL = &PL_sv_undef;
    }
  OUTPUT:
    RETVAL

SV *
hasflag( nodesv, keysv )
  SV *nodesv
  SV *keysv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    STRLEN len;
    char *key;
    xjr_node *sub;
  CODE:
    pnode = INT2PTR( xjr_pnode *, SvUV( SvRV( nodesv ) ) );
    node = pnode->node;
    key = SvPV(keysv, len);
    sub = xjr_node__get(node, key, len);
    if( !sub ) {
      RETVAL = &PL_sv_undef;
    }
    else {
      //xjr_pnode *subPnode = xjr_pnode__new( sub, 0, 0 );
      if( sub->flags & FLAG_FLAG ) {
        RETVAL = newSVuv( 1 );
      }
      else {
        RETVAL = &PL_sv_undef;
      }
    }
  OUTPUT:
    RETVAL

SV *
jsa( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
    xml_output *output;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    output = xjr_node__jsa( node, 0 );
    val = xml_output__flatten( output, &len );
    xml_output__delete( output );
    RETVAL = fakeStr( val, len );
  OUTPUT:
    RETVAL
    
SV *
keys( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    xjr_key_arr *keys;
    int i;
    AV *arr;
  CODE:
    arr = newAV();
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    keys = xjr_node__getkeys( node );
    for( i=0;i<keys->count;i++ ) {
      char *key = keys->items[ i ];
      int keylen = keys->sizes[ i ];
      av_push( arr, newSVpv( key, keylen ) );//fakeStr( key, keylen ) );
    }
    xjr_key_arr__delete( keys );
    
    RETVAL = newRV_noinc( arr );
  OUTPUT:
    RETVAL

SV *
tree( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    int len;
    char *val;
    xml_output *output;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    output = xjr_node__tree( node );
    val = xml_output__flatten( output, &len );
    xml_output__delete( output );
    RETVAL = fakeStr( val, len );
  OUTPUT:
    RETVAL

SV *
parent( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    node = xjr_node__parent( node );
    if( node ) {
      pnode = xjr_pnode__new( node, 0, 0 );
      RETVAL = tied_node( newSVuv( PTR2UV( pnode ) ) );
    }
    else {
      RETVAL = &PL_sv_undef;
    }
  OUTPUT:
    RETVAL

SV *
clone( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    node = xjr_node__clone( node, NULL );
    node->flags |= FLAG_ISROOT;
    pnode = xjr_pnode__new( node, 0, 0 );
    RETVAL = tied_node( newSVuv( PTR2UV( pnode ) ) );
  OUTPUT:
    RETVAL

SV *
next( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    node = xjr_node__next( node );
    pnode = xjr_pnode__new( node, 0, 0 );
    RETVAL = node ? tied_node( newSVuv( PTR2UV( pnode ) ) ) : &PL_sv_undef;
  OUTPUT:
    RETVAL

SV *
firstChild( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    node = xjr_node__firstChild( node );
    pnode = xjr_pnode__new( node, 0, 0 );
    RETVAL = node ? tied_node( newSVuv( PTR2UV( pnode ) ) ) : &PL_sv_undef;
  OUTPUT:
    RETVAL

void
remove( nodesv )
  SV *nodesv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
  CODE:
    pnode = cast_magic( nodesv, xjr_pnode * );
    node = pnode->node;
    xjr_node__remove( node );

void
DELETE( nodesv, keysv )
  SV *nodesv
  SV *keysv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    STRLEN len;
    char *key;
  CODE:
    pnode = INT2PTR( xjr_pnode *, SvUV( SvRV( nodesv ) ) );
    node = pnode->node;
    key = SvPV(keysv, len);
    xjr_node__removeall( node, key, len );

SV *
FETCH( nodesv, keysv )
  SV *nodesv
  SV *keysv
  PREINIT:
    xjr_node *node;
    xjr_pnode *pnode;
    xjr_node *sub;
    STRLEN len;
    char *key;
    SV *subsv;
  CODE:
    pnode = INT2PTR( xjr_pnode *, SvUV( SvRV( nodesv ) ) );
    node = pnode->node;
    key = SvPV(keysv, len);
    if( key[0] == '@' ) {
      key++;
      len--;
      xjr_arr *subs = xjr_node__getarr( node, key, len );
      if( !subs ) {
        RETVAL = &PL_sv_undef;
      }
      else {
        AV *arr = newAV();
        int num = subs->count;
        for( int i=0;i<num;i++ ) {
          sub = subs->items[i];
          xjr_pnode *arrItem = xjr_pnode__new( sub, 0, 0 );
          av_push( arr, tied_node( newSVuv( PTR2UV( arrItem ) ) ) );
        }
        xjr_arr__delete( subs );
        RETVAL = newRV_noinc( arr );
      }
    }
    else {
      //printf("Attempting to fetch \"%.*s\" from %p\n", len, key, node );
      sub = xjr_node__get(node, key, len);
      //printf("Got sub %p\n", sub );
      if( !sub ) {
        RETVAL = &PL_sv_undef;
      }
      else {
        xjr_pnode *subPnode = xjr_pnode__new( sub, 0, 0 );
        subsv = newSVuv( PTR2UV( subPnode ) );
        RETVAL = tied_node( subsv );
      }
    }
  OUTPUT:
    RETVAL