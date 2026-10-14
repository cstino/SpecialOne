import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './occhiali.css'
import { Occhiali } from './Occhiali'

createRoot(document.getElementById('occhiali')!).render(<StrictMode><Occhiali /></StrictMode>)
