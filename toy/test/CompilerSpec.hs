{-# LANGUAGE FlexibleContexts, GADTs #-}

module CompilerSpec(spec) where

import Control.Monad.IO.Class
import Control.Monad.Loops
import Data.Either
import Data.Void
import Test.Hspec
import Text.Megaparsec hiding (State)
import Text.SExpression

import Idris.IdeModeClient
import Toy.Language.Compiler
import Toy.Language.Parser.Decl
import Toy.Language.Syntax.Decl

parse' :: String -> IO FunDecl
parse' str = do
  parsed `shouldSatisfy` isRight
  pure $ either (error . show) id parsed
  where
   parsed = runParser (funDecl <* eof) "" str :: Either (ParseErrorBundle String Void) FunDecl

isReturn :: SExpr -> Bool
isReturn (List (Atom ":return" : _)) = True
isReturn _ = False

isOkReply :: SExpr -> Bool
isOkReply (List [Atom ":return", List (Atom ":ok" : _), _]) = True
isOkReply _ = False

spec :: Spec
spec = beforeAll startIdris $ afterAll stopIdris $
  describe "Basic smoke tests" $ do
    it "Parses base types" $ \ih -> do
      parsed <- parse' "someBool : Bool"
      runIdrisClient ih $ do
        sendCommand $ typeCheck $ compileFunDecl parsed
        reply <- iterateUntil isReturn readReply
        liftIO $ reply `shouldSatisfy` isOkReply