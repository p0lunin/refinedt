{-# LANGUAGE ConstraintKinds, TypeFamilies, FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Toy.Language.Parser.Util where

import Data.Char
import Data.Functor
import Data.String
import GHC.Exts
import Text.Megaparsec
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer as ML

type ToyMonad e s m = (MonadParsec e s m,
                       Token s ~ Char, IsString (Tokens s),
                       IsList (Tokens s), Item (Tokens s) ~ Char)

identifier :: ToyMonad e s m => m String
identifier = do
  firstLetter <- letterChar
  rest <- takeWhileP (Just "variable") isAlphaNum
  pure $ firstLetter : toList rest

-- Utils

parseTable :: ToyMonad e s m => [(Tokens s, a)] -> m a
parseTable table = choice [ lstring str $> op | (str, op) <- table ]

lexeme' :: ToyMonad e s m => m a -> m a
lexeme' = lexeme lexSpace

lstring :: ToyMonad e s m => Tokens s -> m (Tokens s)
lstring = try . lexeme' . string

lstringSpace :: ToyMonad e s m => Tokens s -> m (Tokens s)
lstringSpace s = try $ lexeme' $ string s <* space1

lsymbol :: ToyMonad e s m => Tokens s -> m (Tokens s)
lsymbol = ML.symbol lexSpace

parens :: ToyMonad e s m => m a -> m a
parens = between (lsymbol "(") (lsymbol ")")

lexSpace :: ToyMonad e s m => m ()
lexSpace = ML.space space1 empty empty
