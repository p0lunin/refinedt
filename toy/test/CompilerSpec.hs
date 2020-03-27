{-# LANGUAGE FlexibleContexts, GADTs #-}
{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses, UndecidableInstances #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module CompilerSpec(spec) where

import Control.Monad.IO.Class
import Control.Monad.Loops
import Control.Monad.State.Strict
import Data.Either
import Data.List.Extra
import Data.Void
import QuickCheck.GenT
import Test.Hspec
import Text.Megaparsec hiding (State)
import Text.SExpression

import Idris.IdeModeClient
import Toy.Language.Compiler
import Toy.Language.Parser.Decl
import Toy.Language.Syntax.Decl
import Toy.Language.Syntax.Types

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

checkIdris :: String -> IdrisHandle -> Expectation
checkIdris declStr ih = do
  parsed <- parse' declStr
  runIdrisClient ih $ withFile $ \file -> do
    write file $ compileFunDecl parsed
    sendCommand $ loadFile file
    reply <- iterateUntil isReturn readReply
    liftIO $ reply `shouldSatisfy` isOkReply

spec :: Spec
spec = beforeAll startIdris $ afterAll stopIdris $
  describe "Basic smoke tests" $ do
    it "Compiles base types" $ checkIdris "someBool : Bool"
    describe "Compiles arrow types" $ do
      it "base types" $ checkIdris "someFun : Int -> Bool"
      it "refinements" $ checkIdris "someFun : { ν : Int | ν > 0 } -> Bool"
      it "pi-bound vars" $ checkIdris "someFun : (x : Int) -> Bool"
      it "pi-bound vars and refinements" $ checkIdris "someFun : (x : { ν : Int | ν > 0 }) -> Bool"

instance Arbitrary Ty where
  arbitrary = (`evalState` []) <$> runGenT genTy

genTy :: MonadState [(VarName, BaseTy)] m => GenT m Ty
genTy = frequency [ (3, TyArrow <$> genTyArrow)
                  , (2, TyBase <$> genTyBase)
                  ]
  where
    genTyArrow = do
      domTy <- genTy
      piVarName <- case domTy of
                        TyArrow {} -> pure Nothing
                        TyBase rbTy -> do
                          cnt <- gets length
                          let name = VarName $ "a" <> show cnt
                          modify' ((name, baseType rbTy) :)
                          pure $ Just name
      codTy <- genTy
      pure ArrowTy { .. }

    genTyBase = RefinedBaseTy <$> elements enumerate <*> genRefinement
    genRefinement = Refinement <$> listOf genAtomicRefinement
    genAtomicRefinement = AR <$> genRefinementOp <*> genRefinementArg
    genRefinementOp = elements enumerate
    genRefinementArg = do
      vars <- get
      elements $ RArgZero
               : [ RArgVar var | (var, TInt) <- vars ]
              <> [ RArgVarLen var | (var, TIntList) <- vars ]

instance MonadState s m => MonadState s (GenT m) where
  state = lift . state
  get = lift get
  put = lift . put
