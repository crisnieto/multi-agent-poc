import React from 'react';
import { createRoot } from 'react-dom/client';
import { LocalDemo } from './pages/LocalDemo';
import { Dashboard } from './pages/Dashboard';
import './style.css';

const demo = new URLSearchParams(window.location.search).get('mode') === 'demo';
createRoot(document.getElementById('root')!).render(<React.StrictMode>{demo ? <LocalDemo /> : <Dashboard />}</React.StrictMode>);
