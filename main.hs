
-- Main program

import Expr
import Infer
import Parser
import InputParser
import System.Environment (getArgs)
import System.Console.GetOpt
import System.Process
import Data.List (find, intercalate, nub)
import Data.Set (toAscList)

-- Wrapper for expression parser
parseProg :: String -> [Type] -> Either String [(Type, Exp Lit)]
parseProg prog types = inferType (foldr typeConstr (Scheme ["x"] $ TVar "x") types) <$> parseExpr prog
  where typeConstr typ1 (Scheme vars typ2) = Scheme (nub $ vars ++ toAscList (freeVars typ1)) $ TFun typ1 typ2

-- Command line option flags
data Flag = InferType
          | InFile
          | OutFile String
          deriving (Eq)

isOutFile :: Flag -> Bool
isOutFile (OutFile _) = True
isOutFile _ = False

-- Command line options
consoleOpts :: [OptDescr Flag]
consoleOpts = [Option ['i'] ["infer"] (NoArg InferType) "only infer type(s) of given program",
               Option ['f'] ["file"] (NoArg InFile) "read program from file",
               Option ['o'] ["out"] (ReqArg OutFile "FILE") "produce Haskell file of given name"]

produceFile :: String -> Type -> Exp Lit -> String
produceFile defs typ expr =
  defs ++
  "func :: " ++ typeToHaskell typ ++ "\n" ++
  "func = " ++ expToHaskell expr ++ "\n" ++
  "main :: IO ()\n" ++
  "main = do{[" ++ intercalate "," argList ++ "] <- getArgs; " ++
  "let{res = func " ++ concatMap (\a -> "(read " ++ a ++ ")") argList ++ "}; " ++
  "putStrLn (show res)}"
  where argList = ["arg" ++ show i | i <- [1..numArgs typ]]
        numArgs (TFun _ t) = 1 + numArgs t
        numArgs _ = 0

main = do
  args <- getArgs
  let parsedArgs = getOpt RequireOrder consoleOpts args
  case parsedArgs of
    (opts, (progOrFile : progArgs), []) -> do
      prog <- if InFile `elem` opts
              then readFile progOrFile
              else return progOrFile
      if InferType `elem` opts
        then case parseProg prog [] of
               Left err -> putStrLn err
               Right typings -> flip mapM_ typings $ \(typ, expr) ->
                                                       putStrLn $ show expr ++ " :: " ++ show typ
        else do
        let outfile = case (find isOutFile opts, InFile `elem` opts) of
                        (Just (OutFile s), _) -> s
                        (Nothing, True) -> progOrFile ++ ".hs"
                        (Nothing, False) -> ".out.hs"
            progInputs :: Either String (Maybe [(String,Type)])
            progInputs = fmap sequence $ sequence $ zipWith parseInput [1..] progArgs
        defs <- readFile "defs.hs"
        case progInputs of
          Left err          -> putStrLn err
          Right Nothing     -> putStrLn "Could not infer valid type(s) for input(s)"
          Right (Just typedArgs) ->
            case parseProg prog (map snd typedArgs) of
              Left err             -> putStrLn err
              Right []             -> putStrLn "Could not infer valid type for program"
              Right ((typ,expr):_) -> do writeFile outfile $ produceFile defs typ expr
                                         putStrLn =<< readProcess "runhaskell" (outfile : map fst typedArgs) ""
    (_, _, errs) -> putStrLn $ concat errs ++ "Usage: main [OPTION...] [FILE|EXPR] [INPUT...]"
